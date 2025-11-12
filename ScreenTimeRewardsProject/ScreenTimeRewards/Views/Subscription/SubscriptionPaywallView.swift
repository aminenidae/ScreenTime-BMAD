import SwiftUI
import StoreKit

struct SubscriptionPaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTier: SubscriptionTier = .individual
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    var isOnboarding: Bool = false
    var onComplete: (() -> Void)? = nil

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    trialBanner
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
            Text("30-DAY FREE TRIAL")
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

    var tierSelector: some View {
        VStack(spacing: 12) {
            tierCard(.individual)
            tierCard(.family)
        }
    }

    func tierCard(_ tier: SubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        let product = subscriptionManager.product(for: tier)

        return Button {
            selectedTier = tier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tier.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(tier == .family ? "Up to 5 child devices" : "Perfect for one child")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    if let product {
                        Text(product.displayPrice)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
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
                } else {
                    Text(isOnboarding ? "Start Free Trial" : "Continue")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.vibrantTeal)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isPurchasing || subscriptionManager.product(for: selectedTier) == nil)
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
            finishFlow()
        } label: {
            Text("Skip (Dev Only)")
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
        guard let product = subscriptionManager.product(for: selectedTier) else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await subscriptionManager.purchase(product)
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
