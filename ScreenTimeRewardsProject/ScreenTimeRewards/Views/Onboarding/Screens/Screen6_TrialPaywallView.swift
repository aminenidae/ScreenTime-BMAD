import SwiftUI
import StoreKit

/// Screen 6: 30-Day Trial + Pricing (C6) with benefit image cards
/// Presents the subscription options with 30-day free trial and visual benefits
/// Adapts to iPad with grid layout and landscape with smaller cards
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
            // Header
            VStack(spacing: 8) {
                Text("Your family system\nis ready")
                    .font(.system(size: layout.isRegular ? 32 : 28, weight: .bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text("For the next 30 days, you'll get full access to all features.")
                    .font(.system(size: layout.isRegular ? 16 : 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.horizontalPadding)
            }
            .padding(.vertical, layout.isLandscape ? 10 : 16)
            .frame(maxWidth: 600)

            ScrollView {
                VStack(spacing: layout.cardSpacing) {
                    // Benefit Image Cards - Grid on iPad, HScroll on iPhone
                    if layout.useGridLayout {
                        // iPad: Side by side
                        HStack(spacing: layout.cardSpacing) {
                            BenefitImageCard(
                                imageName: "onboarding_C6_1",
                                title: "📊 Deep Analytics",
                                subtitle: "Track learning progress in real-time",
                                layout: layout
                            )

                            BenefitImageCard(
                                imageName: "onboarding_C6_2",
                                title: "👨‍👩‍👧‍👦 Manage Multiple Kids",
                                subtitle: "Control all children from one dashboard",
                                layout: layout
                            )
                        }
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 700)
                    } else {
                        // iPhone: Horizontal scroll
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: layout.cardSpacing) {
                                BenefitImageCard(
                                    imageName: "onboarding_C6_1",
                                    title: "📊 Deep Analytics",
                                    subtitle: "Track learning progress in real-time",
                                    layout: layout
                                )

                                BenefitImageCard(
                                    imageName: "onboarding_C6_2",
                                    title: "👨‍👩‍👧‍👦 Manage Multiple Kids",
                                    subtitle: "Control all children from one dashboard",
                                    layout: layout
                                )
                            }
                            .padding(.horizontal, layout.horizontalPadding)
                            .padding(.vertical, 8)
                        }
                    }

                    // Setup summary card
                    SetupSummaryCard(
                        learningGoal: onboarding.dailyLearningGoalMinutes,
                        rewardMinutes: Int(Double(onboarding.dailyLearningGoalMinutes) * onboarding.learningToRewardRatio),
                        colorScheme: colorScheme
                    )
                    .padding(.horizontal, layout.horizontalPadding)
                    .frame(maxWidth: 500)

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

    // MARK: - Benefit Image Card

    struct BenefitImageCard: View {
        let imageName: String
        let title: String
        let subtitle: String
        let layout: ResponsiveCardLayout

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                // Background image
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: layout.useGridLayout ? nil : layout.benefitCardWidth,
                        height: layout.benefitCardHeight
                    )
                    .clipped()

                // Gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.5)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: layout.isRegular ? 18 : 16, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: layout.isRegular ? 14 : 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(layout.isRegular ? 16 : 12)
            }
            .frame(
                width: layout.useGridLayout ? nil : layout.benefitCardWidth,
                height: layout.benefitCardHeight
            )
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
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

// MARK: - Setup Summary Card

private struct SetupSummaryCard: View {
    let learningGoal: Int
    let rewardMinutes: Int
    let colorScheme: ColorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(learningGoal) min learning")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("automatically unlocks \(rewardMinutes) min rewards")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.vibrantTeal)
                .font(.system(size: 22))
        }
        .padding(14)
        .background(AppTheme.vibrantTeal.opacity(0.1))
        .cornerRadius(12)
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
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("59.99")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            VStack(alignment: .leading, spacing: 0) {
                                Text("USD")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                                Text("Billed Yearly")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            }
                        }

                        Text("(4.99 USD / month effective)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                        // Discount
                        HStack(spacing: 6) {
                            Text("119.88")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .strikethrough()

                            Text("50% off today")
                                .font(.system(size: 11, weight: .semibold))
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
                Text("Start 30-day free trial")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.vibrantTeal)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(isSelected ? AppTheme.vibrantTeal.opacity(0.05) : AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? AppTheme.vibrantTeal : AppTheme.border(for: colorScheme), lineWidth: isSelected ? 2 : 1)
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
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("9.99")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            VStack(alignment: .leading, spacing: 0) {
                                Text("USD")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                                Text("per month")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }

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
                Text("Start 30-day free trial")
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
