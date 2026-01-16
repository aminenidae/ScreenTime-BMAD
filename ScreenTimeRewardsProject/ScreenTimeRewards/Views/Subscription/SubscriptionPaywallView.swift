//
//  SubscriptionPaywallView.swift
//  ScreenTimeRewards
//

import SwiftUI
import RevenueCat
import StoreKit

struct SubscriptionPaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTier: SubscriptionTier = .individual
    @State private var selectedBillingPeriod: BillingPeriod = .annual
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    var isOnboarding: Bool = false
    var onComplete: (() -> Void)? = nil

    enum BillingPeriod: String, CaseIterable {
        case monthly = "Monthly"
        case annual = "Annual"
    }

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    trialBanner
                    billingPeriodSelector
                    tierSelector
                    featureList
                    purchaseButton
                    restoreButton
                    legalText

                    #if DEBUG
                    skipButton
                    #endif
                }
                .padding(24)
            }
        }
        .overlay(alignment: .topTrailing) {
            if subscriptionManager.hasAccess && !isOnboarding {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    /// Get the selected package based on tier and billing period
    private var selectedPackage: Package? {
        switch selectedBillingPeriod {
        case .monthly:
            return subscriptionManager.monthlyPackage(for: selectedTier)
        case .annual:
            return subscriptionManager.annualPackage(for: selectedTier)
        }
    }
}

// MARK: - Sections

private extension SubscriptionPaywallView {
    var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("Unlock Premium")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(AppTheme.vibrantTeal)

            Text("Give your family the tools to balance screen time and learning")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    var trialBanner: some View {
        VStack(spacing: 8) {
            Text("14-DAY FREE TRIAL")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.sunnyYellow)

            Text("Full access, cancel anytime")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.sunnyYellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.sunnyYellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    var billingPeriodSelector: some View {
        HStack(spacing: 12) {
            ForEach(BillingPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedBillingPeriod = period
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(period.rawValue)
                            .font(.system(size: 16, weight: .semibold))

                        if period == .annual {
                            Text("Save ~50%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.sunnyYellow)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedBillingPeriod == period
                                  ? AppTheme.vibrantTeal
                                  : AppTheme.card(for: colorScheme))
                    )
                    .foregroundColor(selectedBillingPeriod == period
                                     ? .white
                                     : AppTheme.textPrimary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var tierSelector: some View {
        VStack(spacing: 12) {
            tierCard(.individual)
            tierCard(.family)
        }
    }

    func tierCard(_ tier: SubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        let package: Package? = selectedBillingPeriod == .monthly
            ? subscriptionManager.monthlyPackage(for: tier)
            : subscriptionManager.annualPackage(for: tier)

        // StoreKit fallback price when RevenueCat unavailable
        let fallbackPrice: String? = selectedBillingPeriod == .monthly
            ? subscriptionManager.storeKitMonthlyPrice(for: tier)
            : subscriptionManager.storeKitAnnualPrice(for: tier)

        return Button {
            selectedTier = tier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tier.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        if tier == .family {
                            Text("BEST VALUE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.sunnyYellow)
                                .cornerRadius(4)
                        }
                    }

                    Text(tierSubtitle(for: tier))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    if let package {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(package.localizedPriceString)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text(selectedBillingPeriod == .monthly ? "/month" : "/year")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }

                        if selectedBillingPeriod == .annual {
                            Text(monthlyEquivalent(for: package))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    } else if let price = fallbackPrice {
                        // StoreKit fallback when RevenueCat offerings unavailable
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(price)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text(selectedBillingPeriod == .monthly ? "/month" : "/year")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }

                        if selectedBillingPeriod == .annual, let product = subscriptionManager.storeKitAnnualProduct(for: tier) {
                            Text(storeKitMonthlyEquivalent(for: product))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Loading...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.vibrantTeal)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? AppTheme.vibrantTeal : .clear, lineWidth: 2)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    func tierSubtitle(for tier: SubscriptionTier) -> String {
        switch tier {
        case .solo:
            return "1 child device, on-device only"
        case .individual:
            return "1 child, 2 parent devices"
        case .family:
            return "Up to 5 children, 2 parents each"
        case .trial:
            return "Full access for 14 days"
        }
    }

    func monthlyEquivalent(for package: Package) -> String {
        let price = package.storeProduct.price as Decimal
        let monthlyPrice = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? Locale.current
        if let formatted = formatter.string(from: monthlyPrice as NSDecimalNumber) {
            return "Just \(formatted)/month"
        }
        return ""
    }

    func storeKitMonthlyEquivalent(for product: Product) -> String {
        let price = product.price
        let monthlyPrice = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        if let formatted = formatter.string(from: monthlyPrice as NSDecimalNumber) {
            return "Just \(formatted)/month"
        }
        return ""
    }

    var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Features")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(selectedTier.features, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(AppTheme.vibrantTeal)
                    Text(feature)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    var purchaseButton: some View {
        Button {
            if isOnboarding && subscriptionManager.hasAccess {
                onComplete?()
            } else {
                Task {
                    await purchase()
                }
            }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(buttonText)
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.vibrantTeal)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isPurchasing || selectedPackage == nil)
        .opacity(selectedPackage == nil ? 0.6 : 1.0)
    }

    var buttonText: String {
        if isOnboarding {
            return "Start Free Trial"
        } else if let package = selectedPackage {
            return "Subscribe for \(package.localizedPriceString)"
        } else {
            return "Continue"
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
            Text("Cancel anytime. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://screentimerewards.com/terms")!)
                Text("•")
                Link("Privacy Policy", destination: URL(string: "https://screentimerewards.com/privacy")!)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    #if DEBUG
    var skipButton: some View {
        Button {
            subscriptionManager.activateDevSubscription(tier: selectedTier)
            finishFlow()
        } label: {
            Text("Skip with \(selectedTier.displayName) (Dev)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red.opacity(0.7))
        }
        .padding(.top, 8)
    }
    #endif
}

// MARK: - Actions

private extension SubscriptionPaywallView {
    func purchase() async {
        guard let package = selectedPackage else {
            errorMessage = "No subscription package available"
            showError = true
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await subscriptionManager.purchase(package)
            await MainActor.run {
                finishFlow()
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
                    finishFlow()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func finishFlow() {
        if isOnboarding {
            onComplete?()
        } else {
            dismiss()
        }
    }
}
