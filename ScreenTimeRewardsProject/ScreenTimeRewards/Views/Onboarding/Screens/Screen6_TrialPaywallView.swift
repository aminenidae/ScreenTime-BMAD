//
//  Screen6_TrialPaywallView.swift
//  ScreenTimeRewards
//

import SwiftUI
import RevenueCat

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

    private var layout: ResponsiveCardLayout {
        ResponsiveCardLayout(horizontal: hSizeClass, vertical: vSizeClass)
    }

    /// Get the annual Family package from RevenueCat
    private var annualPackage: Package? {
        subscriptionManager.annualPackage(for: .family)
    }

    /// Get the monthly Family package from RevenueCat
    private var monthlyPackage: Package? {
        subscriptionManager.monthlyPackage(for: .family)
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

                    // Annual card (PROMINENT)
                    AnnualPlanCard(
                        isSelected: selectedPlan == .annual,
                        colorScheme: colorScheme,
                        package: annualPackage,
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

            // Legal fine print
            Text("14-day free trial. No charge until your trial ends.\nYou can cancel anytime in your iPhone settings.")
                .font(.system(size: 12, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.bottom, layout.isLandscape ? 8 : 12)
                .textCase(.uppercase)

            // Skip link
            Button(action: { showConfirmSkip = true }) {
                Text("Skip trial and delete setup")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red.opacity(0.8))
                    .textCase(.uppercase)
            }
            .padding(.bottom, 8)

            // DEBUG: Skip without deleting settings (for development)
            #if DEBUG
            Button(action: {
                onboarding.logEvent("onboarding_dev_skip_paywall")
                onboarding.advanceScreen()
            }) {
                Text("Dev: Skip & Keep Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue.opacity(0.7))
            }
            .padding(.bottom, layout.isLandscape ? 12 : 20)
            #else
            Spacer().frame(height: 12)
            #endif
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
        .overlay {
            if isPurchasing {
                PurchasingOverlay()
            }
        }
        .onAppear {
            onboarding.logScreenView(screenNumber: 6)
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

        Task {
            do {
                try await subscriptionManager.purchase(package)
                onboarding.trialStartDate = Date()
                onboarding.logEvent("onboarding_trial_started", params: ["plan": selectedPlan.rawValue])
                onboarding.advanceScreen()
            } catch SubscriptionError.userCancelled {
                // User cancelled, no error to show
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
    let onSelect: () -> Void
    let onPurchase: () -> Void

    /// Calculate monthly equivalent from annual price
    private var monthlyEquivalent: String {
        guard let package else { return "" }
        let price = package.storeProduct.price as Decimal
        let monthlyPrice = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale ?? Locale.current
        return formatter.string(from: monthlyPrice as NSDecimalNumber) ?? ""
    }

    /// Calculate savings percentage vs monthly
    private var savingsText: String {
        // Family annual is ~$75/year vs ~$12.49/month ($150/year) = 50% savings
        return "50% off today"
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

                        // Price - dynamic from RevenueCat
                        VStack(alignment: .leading, spacing: 2) {
                            if let package {
                                Text("\(monthlyEquivalent) / month")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                    .textCase(.uppercase)

                                Text("\(package.localizedPriceString) billed annually")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                    .textCase(.uppercase)
                            } else {
                                Text("Loading...")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }

                        // Discount
                        HStack(spacing: 6) {
                            Text(savingsText)
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
            .padding(.bottom, 16)
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
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Price - dynamic from RevenueCat
                        if let package {
                            Text("\(package.localizedPriceString) / month")
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
                Text("Start 14-Day Free Trial")
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
            .padding(.bottom, 16)
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
