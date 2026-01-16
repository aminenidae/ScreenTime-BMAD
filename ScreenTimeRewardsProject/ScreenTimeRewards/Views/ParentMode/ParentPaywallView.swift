//
//  ParentPaywallView.swift
//  ScreenTimeRewards
//
//  Paywall shown on parent device for Individual and Family subscription tiers.
//  Subscription is purchased here and validated via Firebase for child pairing.
//

import SwiftUI
import RevenueCat
import StoreKit

struct ParentPaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTier: SubscriptionTier = .family
    @State private var selectedBilling: BillingPeriod = .annual
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showRestoreSuccess = false

    let onSubscribed: () -> Void
    var onSkip: (() -> Void)?

    enum BillingPeriod {
        case monthly
        case annual
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Value propositions
                    valuePropositions
                        .padding(.top, 16)

                    // Tier selection
                    tierSelectionSection

                    // Billing toggle
                    billingToggle

                    // Price display
                    priceDisplay

                    // Subscribe button
                    subscribeButton

                    // Legal
                    legalText

                    // Restore purchases
                    restoreButton

                    #if DEBUG
                    // Dev skip button
                    devSkipButton
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .overlay {
            if isPurchasing {
                purchasingOverlay
            }
        }
        .alert("Purchases Restored", isPresented: $showRestoreSuccess) {
            Button("OK") {
                if subscriptionManager.hasAccess {
                    onSubscribed()
                }
            }
        } message: {
            Text(subscriptionManager.hasAccess
                 ? "Your subscription has been restored."
                 : "No previous purchases found.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            HStack {
                if let onSkip {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    }
                }
                Spacer()
            }

            Text("CHOOSE YOUR PLAN")
                .font(.system(size: 16, weight: .bold))
                .tracking(2)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Value Propositions

    private var valuePropositions: some View {
        VStack(alignment: .leading, spacing: 12) {
            ValueRow(icon: "iphone.gen3.radiowaves.left.and.right", text: "Monitor your child remotely")
            ValueRow(icon: "chart.bar.fill", text: "Track learning progress in real-time")
            ValueRow(icon: "shield.checkered", text: "Control app access from anywhere")
            ValueRow(icon: "person.2.fill", text: "Connect up to 2 parent devices")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    // MARK: - Tier Selection

    private var tierSelectionSection: some View {
        VStack(spacing: 12) {
            TierOptionCard(
                tier: .individual,
                isSelected: selectedTier == .individual,
                colorScheme: colorScheme,
                onSelect: { selectedTier = .individual }
            )

            TierOptionCard(
                tier: .family,
                isSelected: selectedTier == .family,
                colorScheme: colorScheme,
                onSelect: { selectedTier = .family }
            )
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingOption(period: .monthly, label: "Monthly")
            billingOption(period: .annual, label: "Annual")
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    private func billingOption(period: BillingPeriod, label: String) -> some View {
        Button(action: { selectedBilling = period }) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(selectedBilling == period
                                     ? .white
                                     : AppTheme.brandedText(for: colorScheme))

                if period == .annual {
                    Text("Save 50%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(selectedBilling == period
                                         ? AppTheme.sunnyYellow
                                         : AppTheme.vibrantTeal)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedBilling == period ? AppTheme.vibrantTeal : Color.clear)
            )
            .padding(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Price Display

    private var priceDisplay: some View {
        VStack(spacing: 8) {
            if let package = currentPackage {
                Text(package.localizedPriceString)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text(selectedBilling == .annual ? "per year" : "per month")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))

                if selectedBilling == .annual {
                    Text("That's just \(monthlyEquivalent)/month")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            } else if let fallbackPrice = currentFallbackPrice {
                // StoreKit fallback when RevenueCat offerings unavailable
                Text(fallbackPrice)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text(selectedBilling == .annual ? "per year" : "per month")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))

                if selectedBilling == .annual {
                    Text("That's just \(storeKitMonthlyEquivalent)/month")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            } else {
                ProgressView()
                    .padding()
            }
        }
        .padding(.vertical, 16)
    }

    private var currentPackage: Package? {
        if selectedBilling == .annual {
            return subscriptionManager.annualPackage(for: selectedTier)
        } else {
            return subscriptionManager.monthlyPackage(for: selectedTier)
        }
    }

    private var currentFallbackPrice: String? {
        if selectedBilling == .annual {
            return subscriptionManager.storeKitAnnualPrice(for: selectedTier)
        } else {
            return subscriptionManager.storeKitMonthlyPrice(for: selectedTier)
        }
    }

    private var monthlyEquivalent: String {
        guard let package = subscriptionManager.annualPackage(for: selectedTier) else { return "" }
        let price = package.storeProduct.price as Decimal
        let monthlyPrice = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? Locale.current
        return formatter.string(from: monthlyPrice as NSDecimalNumber) ?? ""
    }

    private var storeKitMonthlyEquivalent: String {
        guard let product = subscriptionManager.storeKitAnnualProduct(for: selectedTier) else { return "" }
        let price = product.price
        let monthlyPrice = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        return formatter.string(from: monthlyPrice as NSDecimalNumber) ?? ""
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button(action: purchase) {
            HStack {
                Text("Subscribe Now")
                    .font(.system(size: 18, weight: .bold))

                if let package = currentPackage {
                    Text("- \(package.localizedPriceString)")
                        .font(.system(size: 16, weight: .medium))
                } else if let price = currentFallbackPrice {
                    Text("- \(price)")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(AppTheme.vibrantTeal)
            .cornerRadius(16)
        }
        .disabled(currentPackage == nil || isPurchasing)
        .opacity(currentPackage == nil ? 0.6 : 1.0)
    }

    // MARK: - Legal Text

    private var legalText: some View {
        VStack(spacing: 8) {
            if let error = purchaseError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless canceled at least 24 hours before the end of the current period.")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button(action: restore) {
            Text("Restore Purchases")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.vibrantTeal)
        }
        .disabled(isPurchasing)
    }

    // MARK: - Dev Skip Button

    #if DEBUG
    private var devSkipButton: some View {
        Button {
            subscriptionManager.activateDevSubscription(tier: selectedTier)
            onSubscribed()
        } label: {
            Text("Skip with \(selectedTier.displayName) (Dev)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red.opacity(0.7))
        }
        .padding(.top, 8)
    }
    #endif

    // MARK: - Purchasing Overlay

    private var purchasingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Processing...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color.black.opacity(0.7))
            .cornerRadius(16)
        }
    }

    // MARK: - Actions

    private func purchase() {
        guard let package = currentPackage else {
            purchaseError = "Unable to load subscription. Please try again."
            return
        }

        isPurchasing = true
        purchaseError = nil

        Task {
            do {
                try await subscriptionManager.purchase(package)

                // Create Firebase family for pairing
                await subscriptionManager.createFirebaseFamilyIfNeeded()

                onSubscribed()
            } catch SubscriptionError.userCancelled {
                // User cancelled - no error
            } catch {
                purchaseError = error.localizedDescription
            }
            isPurchasing = false
        }
    }

    private func restore() {
        isPurchasing = true
        purchaseError = nil

        Task {
            do {
                try await subscriptionManager.restorePurchases()
                showRestoreSuccess = true
            } catch {
                purchaseError = error.localizedDescription
            }
            isPurchasing = false
        }
    }
}

// MARK: - Supporting Views

private struct ValueRow: View {
    let icon: String
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppTheme.vibrantTeal)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
        }
    }
}

private struct TierOptionCard: View {
    let tier: SubscriptionTier
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tier.displayName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))

                        if tier == .family {
                            Text("POPULAR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.vibrantTeal)
                                .cornerRadius(4)
                        }
                    }

                    Text(tierDescription)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppTheme.vibrantTeal : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(AppTheme.vibrantTeal)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.card(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppTheme.vibrantTeal : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var tierDescription: String {
        switch tier {
        case .individual:
            return "1 child device, 2 parent devices"
        case .family:
            return "Up to 5 children, 2 parents each"
        default:
            return ""
        }
    }
}

// MARK: - Preview

#Preview {
    ParentPaywallView(onSubscribed: {})
        .environmentObject(SubscriptionManager.shared)
}
