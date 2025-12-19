import SwiftUI
import StoreKit

/// Screen 6: 30-Day Trial + Pricing (C6)
/// Presents the subscription options with 30-day free trial
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
                        .cornerRadius(16)
                        .padding(.horizontal, layout.horizontalPadding)

                    // Value propositions
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "gift.fill")
                                .foregroundColor(AppTheme.vibrantTeal)
                            Text("Kids Earn Rewards. Not Just Rules.")
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(AppTheme.vibrantTeal)
                            Text("Learning Feels Like Winning.")
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(AppTheme.vibrantTeal)
                            Text("Parents Relax. Kids Stay Engaged.")
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, layout.horizontalPadding)

                    // Annual card (PROMINENT)
                    AnnualPlanCard(
                        isSelected: selectedPlan == .annual,
                        colorScheme: colorScheme,
                        onSelect: { selectedPlan = .annual },
                        onPurchase: { purchaseAnnual() }
                    )
                    .padding(.horizontal, layout.horizontalPadding)
                    .frame(maxWidth: 500)

                    // Monthly card
                    MonthlyPlanCard(
                        isSelected: selectedPlan == .monthly,
                        colorScheme: colorScheme,
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
            Text("30-day free trial. No charge until your trial ends.\nYou can cancel anytime in your iPhone settings.")
                .font(.system(size: 12, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.bottom, layout.isLandscape ? 8 : 12)

            // Skip link
            Button(action: { showConfirmSkip = true }) {
                Text("Skip trial and delete setup")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red.opacity(0.8))
            }
            .padding(.bottom, 8)

            // DEBUG: Skip without deleting settings (for development)
            #if DEBUG
            Button(action: {
                onboarding.logEvent("onboarding_dev_skip_paywall")
                onboarding.advanceScreen()
            }) {
                Text("🔧 Dev: Skip & Keep Settings")
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
        guard let product = subscriptionManager.product(for: .family) else {
            purchaseError = "Unable to load subscription. Please try again."
            return
        }
        purchase(product)
    }

    private func purchaseMonthly() {
        guard let product = subscriptionManager.product(for: .family) else {
            purchaseError = "Unable to load subscription. Please try again."
            return
        }
        purchase(product)
    }

    private func purchase(_ product: Product) {
        isPurchasing = true
        purchaseError = nil

        Task {
            do {
                try await subscriptionManager.purchase(product)
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
    let onSelect: () -> Void
    let onPurchase: () -> Void

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
                        }
                        .foregroundColor(AppTheme.vibrantTeal)

                        // Price
                        VStack(alignment: .leading, spacing: 2) {
                            Text("4.99 USD / month")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text("59.99 USD billed annually")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }

                        // Discount
                        HStack(spacing: 6) {
                            Text("119.88")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .strikethrough()

                            Text("50% off today")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppTheme.vibrantTeal)
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
                Text("Start 30-Day Free Trial")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(red: 0.85, green: 0.65, blue: 0.13), lineWidth: 2)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.85, green: 0.65, blue: 0.13), lineWidth: 2)
        )
    }
}

// MARK: - Monthly Plan Card

private struct MonthlyPlanCard: View {
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Price
                        Text("9.99 USD / month")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        Text("Cancel anytime")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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
                Text("Start 30-Day Free Trial")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme), lineWidth: isSelected ? 2 : 1)
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
