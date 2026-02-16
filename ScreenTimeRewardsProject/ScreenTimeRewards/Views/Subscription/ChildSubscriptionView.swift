//
//  ChildSubscriptionView.swift
//  ScreenTimeRewards
//
//  Subscription view shown on child devices - displays Solo plan only
//  with an alternative path to connect with a parent's subscription.
//

import SwiftUI
import RevenueCat

/// Subscription view for child devices showing Solo plan and parent pairing option
struct ChildSubscriptionView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedBillingPeriod: BillingPeriod = .annual
    @State private var isPurchasing = false
        @State private var showError = false
    @State private var errorMessage = ""

    var onComplete: (() -> Void)?

    enum BillingPeriod: String, CaseIterable {
        case monthly = "Monthly"
        case annual = "Annual"
    }

    private var selectedPackage: Package? {
        switch selectedBillingPeriod {
        case .monthly:
            return subscriptionManager.monthlyPackage(for: .solo)
        case .annual:
            return subscriptionManager.annualPackage(for: .solo)
        }
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

            Text("Continue Using Brain Coinz")
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

            // Price
            priceSection

            // Features
            featuresSection

            // Subscribe button
            subscribeButton
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
                        Text(period.rawValue)
                            .font(.system(size: 14, weight: .semibold))

                        if period == .annual {
                            Text("Save ~50%")
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

                    Text(selectedBillingPeriod == .monthly ? "/month" : "/year")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                if selectedBillingPeriod == .annual {
                    Text(monthlyEquivalent(for: package))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if let price = fallbackPrice {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(price)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(selectedBillingPeriod == .monthly ? "/month" : "/year")
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
                if isPurchasing {
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
        .disabled(isPurchasing || selectedPackage == nil)
        .opacity(selectedPackage == nil ? 0.6 : 1.0)
    }

    var buttonText: String {
        if let package = selectedPackage {
            return "Subscribe for \(package.localizedPriceString)"
        }
        return "Subscribe"
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
                stepRow(number: 1, text: "Parent subscribes on their phone")
                stepRow(number: 2, text: "They generate a pairing code")
                stepRow(number: 3, text: "Scan to connect and unlock this device")
            }
            .padding(.vertical, 8)
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
            Text("Cancel anytime. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://i6dev.ca/braincoinz/terms.html")!)
                Text("|")
                    .foregroundColor(.secondary)
                Link("Privacy Policy", destination: URL(string: "https://i6dev.ca/braincoinz/privacy.html")!)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Actions

private extension ChildSubscriptionView {

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
                onComplete?()
                dismiss()
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
