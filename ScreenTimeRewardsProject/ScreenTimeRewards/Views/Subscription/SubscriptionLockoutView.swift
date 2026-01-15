import SwiftUI

struct SubscriptionLockoutView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.secondary)

                VStack(spacing: 16) {
                    Text("Subscription Required")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Your free trial has ended. Subscribe to continue using ScreenTime Rewards.")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    showPaywall = true
                } label: {
                    Text("View Plans")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.vibrantTeal)
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Text("You can still review your data from Settings.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }
}
