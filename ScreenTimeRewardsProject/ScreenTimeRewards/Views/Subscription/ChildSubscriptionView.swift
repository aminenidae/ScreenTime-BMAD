//
//  ChildSubscriptionView.swift
//  ScreenTimeRewards
//
//  Subscription view shown on child devices - displays Solo plan only
//  with an alternative path to connect with a parent's subscription.
//

import SwiftUI
import StoreKit
import RevenueCat

/// Subscription view for child devices showing Solo plan and parent pairing option
struct ChildSubscriptionView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedBillingPeriod: BillingPeriod = .annual
    @State private var isPurchasing = false
    @State private var isLoadingProducts = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPairingView = false

    var onComplete: (() -> Void)?

    enum BillingPeriod: String, CaseIterable {
        case monthly = "Monthly"
        case annual = "Annual"

        var displayName: String {
            switch self {
            case .monthly: return String(localized: "Monthly")
            case .annual: return String(localized: "Annual")
            }
        }
    }

    private var selectedPackage: Package? {
        switch selectedBillingPeriod {
        case .monthly:
            return subscriptionManager.monthlyPackage(for: .solo)
        case .annual:
            return subscriptionManager.annualPackage(for: .solo)
        }
    }

    private var selectedStoreKitProduct: Product? {
        switch selectedBillingPeriod {
        case .monthly: return subscriptionManager.storeKitMonthlyProduct(for: .solo)
        case .annual:  return subscriptionManager.storeKitAnnualProduct(for: .solo)
        }
    }

    /// Actual savings % for annual vs monthly — avoids hardcoded inaccurate values
    private var annualSavingsPercent: Int? {
        guard let annual = subscriptionManager.annualPackage(for: .solo),
              let monthly = subscriptionManager.monthlyPackage(for: .solo) else { return nil }
        let annualPerMonth = (annual.storeProduct.price as Decimal) / 12
        let monthlyPrice = monthly.storeProduct.price as Decimal
        guard monthlyPrice > 0 else { return nil }
        let savings = (1 - annualPerMonth / monthlyPrice) * 100
        return Int((savings as NSDecimalNumber).doubleValue.rounded())
    }

    /// Check if child is already paired with a parent
    /// Uses subscription tier - child only has .individual/.family if paired with parent
    private var isAlreadyPaired: Bool {
        subscriptionManager.isParentPairedSubscription
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Image("paywall_hero")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipped()
                            .cornerRadius(AppTheme.CornerRadius.large)

                        headerSection
                        soloPlanCard

                        // Only show parent connection option if not already paired
                        if !isAlreadyPaired {
                            orDivider
                            parentSubscriptionCard
                        }

                        restoreButton
                        legalText
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .task {
            guard selectedPackage == nil && selectedStoreKitProduct == nil else { return }
            isLoadingProducts = true
            await subscriptionManager.loadOfferings()
            isLoadingProducts = false
        }
        .sheet(isPresented: $showPairingView) {
            ChildPairingView()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Sections

private extension ChildSubscriptionView {

    var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 50))
                .foregroundColor(AppTheme.vibrantTeal)

            Text("Continue Using Tic Lock")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)

            Text("Choose how to unlock full access")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
    }

    var soloPlanCard: some View {
        VStack(spacing: 16) {
            // Badge
            HStack {
                Text("THIS DEVICE ONLY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(6)

                Spacer()
            }

            // Title
            HStack {
                Text("Solo Plan")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Spacer()
            }

            // Description
            Text("No remote monitoring. Manage everything on this device.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Billing toggle
            billingPeriodSelector

            if selectedBillingPeriod == .annual {
                TrialTimelineView()
                    .padding(.top, 4)
            }

            // Price
            priceSection

            // Features
            featuresSection

            // Subscribe button
            subscribeButton

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("No commitment. Cancel anytime.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
            }
            .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.vibrantTeal, lineWidth: 2)
                )
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 5, x: 0, y: 2)
        )
    }

    var billingPeriodSelector: some View {
        HStack(spacing: 8) {
            ForEach(BillingPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedBillingPeriod = period
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(period.displayName)
                            .font(.system(size: 14, weight: .semibold))

                        if period == .annual {
                            Text(annualSavingsPercent.map { String(localized: "Save ~\($0)%") } ?? String(localized: "Best Value"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedBillingPeriod == period ? .white : AppTheme.sunnyYellow)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedBillingPeriod == period
                                  ? AppTheme.vibrantTeal
                                  : AppTheme.vibrantTeal.opacity(0.1))
                    )
                    .foregroundColor(selectedBillingPeriod == period
                                     ? .white
                                     : AppTheme.textPrimary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var priceSection: some View {
        Group {
            if let package = selectedPackage {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(package.localizedPriceString)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(selectedBillingPeriod == .monthly ? String(localized: "/month") : String(localized: "/year"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                if selectedBillingPeriod == .annual {
                    Text(weeklyEquivalent(for: package))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            } else if let price = fallbackPrice {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(price)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(selectedBillingPeriod == .monthly ? String(localized: "/month") : String(localized: "/year"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Loading prices...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }

    var fallbackPrice: String? {
        selectedBillingPeriod == .monthly
            ? subscriptionManager.storeKitMonthlyPrice(for: .solo)
            : subscriptionManager.storeKitAnnualPrice(for: .solo)
    }

    func weeklyEquivalent(for package: Package) -> String {
        let price = package.storeProduct.price as Decimal
        let weeklyPrice = price / 52
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? Locale.current
        if let formatted = formatter.string(from: weeklyPrice as NSDecimalNumber) {
            return String(localized: "just \(formatted)/week")
        }
        return ""
    }

    var featuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SubscriptionTier.solo.features, id: \.self) { feature in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.vibrantTeal)

                    Text(feature)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var subscribeButton: some View {
        Button {
            Task {
                await purchase()
            }
        } label: {
            HStack {
                if isPurchasing || isLoadingProducts {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(buttonText)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppTheme.vibrantTeal)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isPurchasing || isLoadingProducts || (selectedPackage == nil && selectedStoreKitProduct == nil))
        .opacity((selectedPackage == nil && selectedStoreKitProduct == nil && !isLoadingProducts) ? 0.6 : 1.0)
    }

    var buttonText: String {
        if selectedBillingPeriod == .annual {
            return String(localized: "Start 14-Day Free Trial")
        } else if let package = selectedPackage {
            return String(localized: "Subscribe for \(package.localizedPriceString)")
        }
        return String(localized: "Subscribe")
    }

    var orDivider: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            Text("or")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }

    var parentSubscriptionCard: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.sunnyYellow.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: "person.2.fill")
                    .font(.system(size: 26))
                    .foregroundColor(AppTheme.sunnyYellow)
            }

            // Title
            Text("Connect with Parent's Subscription")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)

            // Description
            Text("If your parent subscribes on their device, you can pair with them and get full access.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Steps
            VStack(alignment: .leading, spacing: 10) {
                stepRow(number: 1, text: String(localized: "Parent subscribes on their phone"))
                stepRow(number: 2, text: String(localized: "They generate a pairing code"))
                stepRow(number: 3, text: String(localized: "Scan to connect and unlock this device"))
            }
            .padding(.vertical, 8)

            Button {
                showPairingView = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18))
                    Text("Scan Parent's QR Code")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.sunnyYellow)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 3, x: 0, y: 1)
        )
    }

    func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.sunnyYellow.opacity(0.2))
                    .frame(width: 24, height: 24)

                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.sunnyYellow)
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }

    var restoreButton: some View {
        Button {
            Task {
                await restore()
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    var legalText: some View {
        VStack(spacing: 8) {
            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. You can manage and cancel your subscriptions by going to your account settings after purchase.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://i6dev.ca/ticlock/terms.html")!)
                Text("|")
                    .foregroundColor(.secondary)
                Link("Privacy Policy", destination: URL(string: "https://i6dev.ca/ticlock/privacy.html")!)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Actions

private extension ChildSubscriptionView {

    func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            if let package = selectedPackage {
                try await subscriptionManager.purchase(package)
            } else if let product = selectedStoreKitProduct {
                try await subscriptionManager.purchaseStoreKitProduct(product)
            } else {
                errorMessage = String(localized: "No subscription package available")
                showError = true
                return
            }
            await MainActor.run {
                if subscriptionManager.hasAccess {
                    onComplete?()
                    dismiss()
                } else {
                    errorMessage = String(localized: "Purchase recorded but activation is pending. Please tap 'Restore Purchases' or restart the app.")
                    showError = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func restore() async {
        do {
            try await subscriptionManager.restorePurchases()
            if subscriptionManager.hasAccess {
                await MainActor.run {
                    onComplete?()
                    dismiss()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Preview

#Preview("Child Subscription View") {
    ChildSubscriptionView()
        .environmentObject(SubscriptionManager.shared)
}
