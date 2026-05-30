//
//  Screen6_TrialPaywallView.swift
//  ScreenTimeRewards
//

import SwiftUI
import RevenueCat
import StoreKit

/// Screen 6: 14-Day Trial + Pricing (C6)
/// Presents the subscription options with 14-day free trial
/// Adapts to iPad with grid layout and landscape mode
struct Screen6_TrialPaywallView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    @State private var selectedPlan: SubscriptionPlanOption = .annual
    @State private var showConfirmSkip = false
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showRestoreSuccess = false

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    /// Tier to display based on onboarding path: solo for "On This Device Only", family for "From a Parent Device"
    private var displayTier: SubscriptionTier {
        onboarding.selectedPath == .solo ? .solo : .family
    }

    /// Get the annual package from RevenueCat for the selected tier
    private var annualPackage: Package? {
        subscriptionManager.annualPackage(for: displayTier)
    }

    /// Get the monthly package from RevenueCat for the selected tier
    private var monthlyPackage: Package? {
        subscriptionManager.monthlyPackage(for: displayTier)
    }

    /// StoreKit fallback prices when RevenueCat unavailable
    private var annualFallbackPrice: String? {
        subscriptionManager.storeKitAnnualPrice(for: displayTier)
    }

    private var monthlyFallbackPrice: String? {
        subscriptionManager.storeKitMonthlyPrice(for: displayTier)
    }

    private var annualFallbackProduct: Product? {
        subscriptionManager.storeKitAnnualProduct(for: displayTier)
    }

    /// Fine print with dynamic post-trial price (Apple guideline 3.1.2(a))
    private var finePrintText: String {
        let appleBoilerplate = "Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. You can manage and cancel your subscriptions by going to your account settings after purchase."
        
        if selectedPlan == .annual {
            let price = annualPackage?.localizedPriceString ?? annualFallbackPrice
            if let price {
                return "Free for 14 days, then \(price)/year.\n\n\(appleBoilerplate)"
            }
            return "Free for 14 days.\n\n\(appleBoilerplate)"
        } else {
            let price = monthlyPackage?.localizedPriceString ?? monthlyFallbackPrice
            if let price {
                return "\(price)/month.\n\n\(appleBoilerplate)"
            }
            return appleBoilerplate
        }
    }

    /// Actual savings % for annual vs monthly — avoids hardcoded inaccurate values
    private var annualSavingsPercent: Int? {
        guard let annual = annualPackage, let monthly = monthlyPackage else { return nil }
        let annualPerMonth = (annual.storeProduct.price as Decimal) / 12
        let monthlyPrice = monthly.storeProduct.price as Decimal
        guard monthlyPrice > 0 else { return nil }
        let savings = (1 - annualPerMonth / monthlyPrice) * 100
        return Int((savings as NSDecimalNumber).doubleValue.rounded())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: layout.cardSpacing) {
                    // Hero image
                    Image("paywall_hero")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: layout.useGridLayout ? 500 : .infinity)
                        .frame(height: layout.isLandscape ? 160 : 200)
                        .clipped()
                        .cornerRadius(AppTheme.CornerRadius.large)
                        .padding(.horizontal, layout.horizontalPadding)

                    // Value propositions
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "gift.fill")
                                .foregroundColor(AppTheme.vibrantTeal)
                            Text("KIDS EARN REWARDS. NOT JUST RULES.")
                                .textCase(.uppercase)
                                .tracking(1.5)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(AppTheme.vibrantTeal)
                            Text("LEARNING FEELS LIKE WINNING.")
                                .textCase(.uppercase)
                                .tracking(1.5)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(AppTheme.vibrantTeal)
                            Text("PARENTS RELAX. KIDS STAY ENGAGED.")
                                .textCase(.uppercase)
                                .tracking(1.5)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .frame(maxWidth: 500)
                    .padding(.horizontal, layout.horizontalPadding)

                    // Trial timeline — Apple-endorsed trust pattern
                    TrialTimelineView()
                        .padding(.horizontal, layout.horizontalPadding)
                        .frame(maxWidth: 500)

                    // Annual card (PROMINENT)
                    AnnualPlanCard(
                        isSelected: selectedPlan == .annual,
                        colorScheme: colorScheme,
                        package: annualPackage,
                        fallbackPrice: annualFallbackPrice,
                        fallbackProduct: annualFallbackProduct,
                        savingsPercent: annualSavingsPercent,
                        onSelect: { selectedPlan = .annual },
                        onPurchase: { purchaseAnnual() }
                    )
                    .padding(.horizontal, layout.horizontalPadding)
                    .frame(maxWidth: 500)

                    // Monthly card
                    MonthlyPlanCard(
                        isSelected: selectedPlan == .monthly,
                        colorScheme: colorScheme,
                        package: monthlyPackage,
                        fallbackPrice: monthlyFallbackPrice,
                        onSelect: { selectedPlan = .monthly },
                        onPurchase: { purchaseMonthly() }
                    )
                    .padding(.horizontal, layout.horizontalPadding)
                    .frame(maxWidth: 500)
                }
            }

            Spacer(minLength: layout.isLandscape ? 8 : 12)

            // Error message
            if let error = purchaseError {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.bottom, 8)
            }

            // Legal fine print — includes post-trial price (Apple 3.1.2(a))
            Text(finePrintText)
                .font(.system(size: 12, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.bottom, 6)
                .textCase(.uppercase)

            // Terms & Privacy links (required for all subscription flows)
            HStack(spacing: 12) {
                Link("Terms of Service", destination: URL(string: "https://i6dev.ca/ticlock/terms.html")!)
                Text("•")
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Link("Privacy Policy", destination: URL(string: "https://i6dev.ca/ticlock/privacy.html")!)
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(AppTheme.vibrantTeal)
            .padding(.bottom, layout.isLandscape ? 8 : 12)

            // Restore purchases (required by App Store)
            Button(action: restorePurchases) {
                Text("Restore Purchases")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .textCase(.uppercase)
            }
            .disabled(isPurchasing)
            .padding(.bottom, 8)

            // Skip link
            Button(action: {
                AppAnalytics.shared.track(.onboardingSkipTapped, parameters: [
                    "from_screen": "paywall",
                    "plan_shown": selectedPlan == .annual ? "annual" : "monthly"
                ])
                showConfirmSkip = true
            }) {
                Text("Skip trial and delete setup")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red.opacity(0.8))
                    .textCase(.uppercase)
            }
            .padding(.bottom, 4)

            #if DEBUG
            // Dev skip button - activates subscription without purchase
            Button {
                subscriptionManager.activateDevSubscription(tier: displayTier)
                onboarding.trialStartDate = Date()
                onboarding.advanceScreen()
            } label: {
                Text("Skip with \(displayTier == .solo ? "Solo" : "Family") (Dev)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
            }
            .padding(.bottom, 4)
            #endif

            Spacer().frame(height: layout.isLandscape ? 12 : 20)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .alert("Delete setup?", isPresented: $showConfirmSkip) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onboarding.resetSetup()
            }
        } message: {
            Text("This will remove all settings you just created. You can always set it up again later.")
        }
        .alert("Purchases Restored", isPresented: $showRestoreSuccess) {
            Button("OK") {
                if subscriptionManager.hasAccess {
                    onboarding.logEvent("onboarding_restore_success")
                    onboarding.advanceScreen()
                }
            }
        } message: {
            Text(subscriptionManager.hasAccess
                 ? "Your subscription has been restored."
                 : "No previous purchases found.")
        }
        .overlay {
            if isPurchasing {
                PurchasingOverlay()
            }
        }
        .onAppear {
            onboarding.logScreenView(screenNumber: 6)
        }
        .onChange(of: selectedPlan) { newPlan in
            AppAnalytics.shared.track(.paywallPlanSwitched, parameters: [
                "source": "onboarding",
                "new_plan": newPlan == .annual ? "annual" : "monthly"
            ])
        }
    }

    private func purchaseAnnual() {
        guard let package = annualPackage else {
            purchaseError = "Unable to load subscription. Please try again."
            return
        }
        purchase(package)
    }

    private func purchaseMonthly() {
        guard let package = monthlyPackage else {
            purchaseError = "Unable to load subscription. Please try again."
            return
        }
        purchase(package)
    }

    private func purchase(_ package: Package) {
        isPurchasing = true
        purchaseError = nil

        AppAnalytics.shared.track(.paywallPurchaseStarted, parameters: [
            "source": "onboarding",
            "plan": selectedPlan == .annual ? "annual" : "monthly",
            "tier": displayTier.rawValue
        ])

        Task {
            do {
                try await subscriptionManager.purchase(package)
                onboarding.trialStartDate = Date()
                AppAnalytics.shared.track(.paywallPurchaseCompleted, parameters: [
                    "source": "onboarding",
                    "plan": selectedPlan == .annual ? "annual" : "monthly",
                    "tier": displayTier.rawValue
                ])
                onboarding.advanceScreen()
            } catch SubscriptionError.userCancelled {
                AppAnalytics.shared.track(.paywallUserCancelled, parameters: [
                    "source": "onboarding",
                    "plan": selectedPlan == .annual ? "annual" : "monthly",
                    "tier": displayTier.rawValue
                ])
            } catch {
                purchaseError = error.localizedDescription
                AppAnalytics.shared.track(.paywallPurchaseFailed, parameters: [
                    "source": "onboarding",
                    "plan": selectedPlan == .annual ? "annual" : "monthly",
                    "error": error.localizedDescription
                ])
            }
            isPurchasing = false
        }
    }

    private func restorePurchases() {
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

// MARK: - Annual Plan Card

private struct AnnualPlanCard: View {
    let isSelected: Bool
    let colorScheme: ColorScheme
    let package: Package?
    let fallbackPrice: String?
    let fallbackProduct: Product?
    let savingsPercent: Int?
    let onSelect: () -> Void
    let onPurchase: () -> Void

    /// Weekly equivalent for secondary display — psychologically cheaper than monthly
    private var weeklyEquivalent: String {
        guard let package else { return "" }
        let price = package.storeProduct.price as Decimal
        let weeklyPrice = price / 52
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? Locale.current
        return formatter.string(from: weeklyPrice as NSDecimalNumber) ?? ""
    }

    /// Weekly equivalent from StoreKit fallback
    private var storeKitWeeklyEquivalent: String {
        guard let product = fallbackProduct else { return "" }
        let price = product.price
        let weeklyPrice = price / 52
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        return formatter.string(from: weeklyPrice as NSDecimalNumber) ?? ""
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Best value badge
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text("BEST VALUE")
                                .font(.system(size: 11, weight: .semibold))
                                .textCase(.uppercase)
                                .tracking(1.5)
                        }
                        .foregroundColor(AppTheme.vibrantTeal)

                        // Price — annual total is headline per Apple guidelines
                        VStack(alignment: .leading, spacing: 2) {
                            if let package {
                                Text("\(package.localizedPriceString) / year")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                    .textCase(.uppercase)

                                Text("just \(weeklyEquivalent) / week")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppTheme.vibrantTeal)
                                    .textCase(.uppercase)
                            } else if let price = fallbackPrice {
                                // StoreKit fallback
                                Text("\(price) / year")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                    .textCase(.uppercase)

                                Text("just \(storeKitWeeklyEquivalent) / week")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                    .textCase(.uppercase)
                            } else {
                                Text("Loading...")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }

                        // Savings — only shown when % is known; badge already says "BEST VALUE"
                        if let pct = savingsPercent {
                            Text("~\(pct)% off today")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppTheme.vibrantTeal)
                                .textCase(.uppercase)
                        }
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? AppTheme.vibrantTeal : .gray)
                        .font(.system(size: 24))
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            Button(action: onPurchase) {
                Text("Start 14-Day Free Trial")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                            .stroke(AppTheme.sunnyYellow, lineWidth: 2)
                    )
                    .textCase(.uppercase)
            }
            .disabled(package == nil)
            .opacity(package == nil ? 0.6 : 1.0)
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("No commitment. Cancel anytime.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .textCase(.uppercase)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(AppTheme.sunnyYellow, lineWidth: 2)
                )
        )
    }
}

// MARK: - Monthly Plan Card

private struct MonthlyPlanCard: View {
    let isSelected: Bool
    let colorScheme: ColorScheme
    let package: Package?
    let fallbackPrice: String?
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Price - dynamic from RevenueCat or StoreKit fallback
                        if let package {
                            Text("\(package.localizedPriceString) / month")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .textCase(.uppercase)
                        } else if let price = fallbackPrice {
                            // StoreKit fallback
                            Text("\(price) / month")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .textCase(.uppercase)
                        } else {
                            Text("Loading...")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }

                        Text("Cancel anytime")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .textCase(.uppercase)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? AppTheme.vibrantTeal : .gray)
                        .font(.system(size: 24))
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            Button(action: onPurchase) {
                Text("Subscribe Monthly")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal.opacity(0.1))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .textCase(.uppercase)
            }
            .disabled(package == nil)
            .opacity(package == nil ? 0.6 : 1.0)
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("No commitment. Cancel anytime.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .textCase(.uppercase)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppTheme.card(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme), lineWidth: isSelected ? 2 : 1)
                )
        )
    }
}

// MARK: - Purchasing Overlay

private struct PurchasingOverlay: View {
    var body: some View {
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
                    .textCase(.uppercase)
            }
            .padding(32)
            .background(Color.black.opacity(0.7))
            .cornerRadius(16)
        }
    }
}

#Preview {
    Screen6_TrialPaywallView()
        .environmentObject(OnboardingStateManager())
        .environmentObject(SubscriptionManager.shared)
}
