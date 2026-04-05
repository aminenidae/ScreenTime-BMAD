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
                    Image("paywall_hero")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(AppTheme.CornerRadius.large)

                    headerSection
                    trialBanner
                    billingPeriodSelector
                    tierSelector
                    featureList
                    purchaseButton
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.vibrantTeal)
                        Text("No commitment. Cancel anytime.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
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

    @ViewBuilder
    var trialBanner: some View {
        if selectedBillingPeriod == .annual {
            TrialTimelineView()
                .padding(.top, 8)
        } else {
            // Optional: Hide entirely for Monthly or keep the simple banner.
            // Since we want free trial for annual ONLY, we return EmptyView or hide it.
            EmptyView()
        }
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
                            Text(annualSavingsPercent(for: selectedTier).map { "Save ~\($0)%" } ?? "Best Value")
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
                            Text(weeklyEquivalent(for: package))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppTheme.vibrantTeal)
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
                            Text(storeKitWeeklyEquivalent(for: product))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppTheme.vibrantTeal)
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

    func weeklyEquivalent(for package: Package) -> String {
        let price = package.storeProduct.price as Decimal
        let weeklyPrice = price / 52
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? Locale.current
        if let formatted = formatter.string(from: weeklyPrice as NSDecimalNumber) {
            return "just \(formatted)/week"
        }
        return ""
    }

    func storeKitWeeklyEquivalent(for product: Product) -> String {
        let price = product.price
        let weeklyPrice = price / 52
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        if let formatted = formatter.string(from: weeklyPrice as NSDecimalNumber) {
            return "just \(formatted)/week"
        }
        return ""
    }

    func annualSavingsPercent(for tier: SubscriptionTier) -> Int? {
        guard let annual = subscriptionManager.annualPackage(for: tier),
              let monthly = subscriptionManager.monthlyPackage(for: tier) else { return nil }
        let annualPerMonth = (annual.storeProduct.price as Decimal) / 12
        let monthlyPrice = monthly.storeProduct.price as Decimal
        guard monthlyPrice > 0 else { return nil }
        let savings = (1 - annualPerMonth / monthlyPrice) * 100
        return Int((savings as NSDecimalNumber).doubleValue.rounded())
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
            if selectedBillingPeriod == .annual {
                return "Start 14-Day Free Trial"
            } else {
                return "Subscribe for \(package.localizedPriceString)"
            }
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
            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. You can manage and cancel your subscriptions by going to your account settings after purchase.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://i6dev.ca/braincoinz/terms.html")!)
                Text("•")
                Link("Privacy Policy", destination: URL(string: "https://i6dev.ca/braincoinz/privacy.html")!)
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
                if subscriptionManager.hasAccess {
                    finishFlow()
                } else {
                    errorMessage = "Purchase recorded but activation is pending. Please tap 'Restore Purchases' or restart the app."
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
